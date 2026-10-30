"""Narrow, lossless script overlay for the pinned binary place.

Keep all non-script chunks opaque, including properties unknown to rbx-dom/Lune.
Only script INST/PROP chunks, the instance count, and PRNT are rebuilt. Ref IDs
of existing objects never change. Unsupported script properties fail closed.
Format reference: https://dom.rojo.space/binary.html
"""
from collections import defaultdict
from dataclasses import dataclass
import struct
import uuid

import lz4.block
import zstandard

SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}
MAGIC = b"<roblox!\x89\xff\r\n\x1a\n\0\0"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def u32(data, offset=0):
    return struct.unpack_from("<I", data, offset)[0]


def string(value):
    return struct.pack("<I", len(value)) + value


def read_string(data, offset):
    size = u32(data, offset)
    end = offset + 4 + size
    need(end <= len(data), "Truncated string")
    return data[offset + 4:end], end


def split_interleaved(data, width, count):
    need(len(data) == width * count, "Invalid interleaved array size")
    return [bytes(data[i + count * j] for j in range(width)) for i in range(count)]


def interleave(values):
    return bytes(b for column in zip(*values) for b in column)


def read_refs(data, count):
    result, current = [], 0
    for value in split_interleaved(data, 4, count):
        unsigned = int.from_bytes(value, "big")
        current += (unsigned >> 1) ^ -(unsigned & 1)
        result.append(current)
    return result


def refs(values):
    result, previous = [], 0
    for value in values:
        delta = value - previous
        need(-(2**31) <= delta < 2**31, "Reference delta overflow")
        result.append(((delta << 1) ^ (delta >> 31)).to_bytes(4, "big"))
        previous = value
    return interleave(result)


@dataclass
class Chunk:
    tag: bytes
    body: bytes
    raw: bytes


def chunk(tag, body):
    compressed = zstandard.ZstdCompressor(level=3).compress(body)
    if len(compressed) < len(body) and tag != b"END\0":
        return tag + struct.pack("<III", len(compressed), len(body), 0) + compressed
    return tag + struct.pack("<III", 0, len(body), 0) + body


def chunks(data):
    need(data[:16] == MAGIC, "Expected a version-0 binary Roblox place")
    offset = 32
    result = []
    while offset < len(data):
        start = offset
        need(offset + 16 <= len(data), "Truncated chunk header")
        tag = data[offset:offset + 4]
        compressed, size, reserved = struct.unpack_from("<III", data, offset + 4)
        need(reserved == 0 and size <= 64 * 1024 * 1024, "Invalid chunk header")
        offset += 16
        raw = data[offset:offset + (compressed or size)]
        need(len(raw) == (compressed or size), "Truncated chunk body")
        offset += len(raw)
        if not compressed:
            body = raw
        elif raw.startswith(b"\x28\xb5\x2f\xfd"):
            body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=size)
        else:
            body = lz4.block.decompress(raw, uncompressed_size=size)
        need(len(body) == size, "Decompressed size mismatch")
        result.append(Chunk(tag, body, data[start:offset]))
        if tag == b"END\0":
            need(body == b"</roblox>" and offset == len(data), "Invalid END chunk")
            return result
    raise ValueError("Missing END chunk")


def property_header(body):
    name, offset = read_string(body, 4)
    return u32(body), name.decode(), body[offset], offset + 1


def values(body, kind, count):
    if kind == 1:
        result, offset = [], 0
        for _ in range(count):
            value, offset = read_string(body, offset)
            result.append(value)
        need(offset == len(body), "Unexpected string property trailer")
        return result
    widths = {2: 1, 18: 4, 27: 8, 28: 4, 31: 16, 33: 8}
    need(kind in widths, f"Unsupported script property type {kind}")
    return split_interleaved(body, widths[kind], count)


def encode_values(items, kind):
    return b"".join(map(string, items)) if kind == 1 else interleave(items)


class Place:
    def __init__(self, data):
        self.data = data
        self.chunks = chunks(data)
        self.classes, self.instances, self.names, self.properties = {}, {}, {}, {}
        self.parents, self.parent_order = {}, []
        self.empty_shared_string = None
        for item in self.chunks:
            body = item.body
            if item.tag == b"INST":
                cid = u32(body)
                name, offset = read_string(body, 4)
                service, count = body[offset], u32(body, offset + 1)
                ids = read_refs(body[offset + 5:offset + 5 + count * 4], count)
                need(cid not in self.classes, "Duplicate class ID")
                need(service in (0, 1) and len(body) == offset + 5 + count * (4 + service), "Invalid INST")
                self.classes[cid] = (name.decode(), ids, service)
                for ref in ids:
                    need(ref >= 0 and ref not in self.instances, "Duplicate/invalid instance ID")
                    self.instances[ref] = cid
            elif item.tag == b"PROP":
                cid, name, kind, offset = property_header(body)
                need(cid in self.classes and (cid, name) not in self.properties, "Invalid/duplicate property")
                self.properties[cid, name] = (kind, body[offset:])
                if name == "Name":
                    need(kind == 1, "Invalid Name property type")
                    self.names.update(zip(self.classes[cid][1], (x.decode() for x in values(body[offset:], kind, len(self.classes[cid][1])))))
            elif item.tag == b"PRNT":
                need(not self.parents and body[0] == 0, "Invalid/duplicate PRNT")
                count = u32(body, 1)
                need(len(body) == 5 + count * 8, "Invalid PRNT size")
                children = read_refs(body[5:5 + count * 4], count)
                parents = read_refs(body[5 + count * 4:], count)
                need(len(set(children)) == count, "Duplicate PRNT child")
                self.parents = dict(zip(children, parents))
                self.parent_order = children
            elif item.tag == b"SSTR":
                need(u32(body) == 0, "Unsupported SSTR version")
                offset = 8
                for i in range(u32(body, 4)):
                    value, offset = read_string(body, offset + 16)
                    if value == b"":
                        self.empty_shared_string = i
                need(offset == len(body), "Invalid SSTR")
        need(len(self.classes) == u32(data, 16) and len(self.instances) == u32(data, 20), "Header counts do not match")
        need(set(self.parents) == set(self.instances) == set(self.names), "Incomplete hierarchy/names")
        self.paths = defaultdict(list)
        for ref in self.instances:
            self.paths[self.path(ref)].append(ref)

    def path(self, ref):
        names, seen = [], set()
        while ref != -1:
            need(ref in self.instances and ref not in seen, "Broken/cyclic hierarchy")
            seen.add(ref)
            names.append(self.names[ref])
            ref = self.parents[ref]
        return ".".join(reversed(names))

    def resolve(self, path):
        found = self.paths.get(path, [])
        need(len(found) == 1, f"Missing or ambiguous instance: {path}")
        return found[0]

    def class_name(self, ref):
        return self.classes[self.instances[ref]][0]

    def scripts(self):
        return [ref for ref in self.instances if self.class_name(ref) in SCRIPT_CLASSES]

    def property(self, ref, name):
        cid = self.instances[ref]
        kind, body = self.properties[cid, name]
        return values(body, kind, len(self.classes[cid][1]))[self.classes[cid][1].index(ref)]

    def asset_chunks(self):
        # Preserve even opaque property types; do not round-trip through a DOM.
        return [item.raw for item in self.chunks if item.tag != b"PRNT" and not (
            item.tag in (b"INST", b"PROP") and self.classes[u32(item.body)][0] in SCRIPT_CLASSES)]


def default_property(name, kind, path, empty_shared_string):
    expected = {"AttributesSerialize": 1, "Capabilities": 33, "DefinesCapabilities": 2,
                "Disabled": 2, "HistoryId": 31, "LinkedSource": 1, "Name": 1,
                "RunContext": 18, "ScriptGuid": 1, "Source": 1, "SourceAssetId": 27,
                "Tags": 28, "UniqueId": 31, "SerializedOverrides": 1}
    need(expected.get(name) == kind, f"Unsupported script property: {name} (type {kind})")
    identifier = uuid.uuid5(uuid.NAMESPACE_URL, "get-funded/source/" + path)
    if name == "ScriptGuid":
        return ("{" + str(identifier).upper() + "}").encode()
    if name == "UniqueId":
        return identifier.bytes
    if name == "Tags":
        need(empty_shared_string is not None, "Base has no empty shared string for new script tags")
        return empty_shared_string.to_bytes(4, "big")
    if name == "SourceAssetId":
        return (1).to_bytes(8, "big")  # zigzag encoded -1
    if kind == 1:
        return b""
    return bytes({2: 1, 18: 4, 31: 16, 33: 8}[kind])


def overlay(base, entries, sources):
    targets = {item["path"]: item for item in entries}
    original_targets = {item.get("previousPath", item["path"]): item for item in entries}
    need(len(targets) == len(entries) and len(original_targets) == len(entries), "Duplicate script target or relocation")
    existing = {}
    for ref in base.scripts():
        path = base.path(ref)
        need(path in original_targets, f"Unexpected or duplicate script: {path}")
        target = original_targets[path]
        need(target["path"] not in existing, f"Duplicate script relocation: {path}")
        need(base.class_name(ref) == target["class"], f"Wrong script class: {path}")
        need(ref not in base.parents.values(), f"Script has children: {path}")
        existing[target["path"]] = ref
    class_ids = {}
    for cid, (name, _, _) in base.classes.items():
        if name in SCRIPT_CLASSES:
            need(name not in class_ids, f"Duplicate script class group: {name}")
            class_ids[name] = cid
    additions = defaultdict(list)
    next_ref = max(base.instances) + 1
    parents = dict(base.parents)
    for item in entries:
        path = item["path"]
        need(item["class"] in class_ids, "Base is missing a required script class")
        if "previousPath" in item:
            need(path in existing, f"Missing script to relocate: {item['previousPath']}")
            parents[existing[path]] = base.resolve(path.rsplit(".", 1)[0])
        if path not in existing:
            existing[path] = next_ref
            additions[class_ids[item["class"]]].append(next_ref)
            parents[next_ref] = base.resolve(path.rsplit(".", 1)[0])
            next_ref += 1
    target_by_ref = {ref: targets[path] for path, ref in existing.items()}
    children = defaultdict(list)
    for ref in base.parent_order + list(range(max(base.instances) + 1, next_ref)):
        children[parents[ref]].append(ref)
    parent_order = []

    def visit(ref):
        for child in children[ref]:
            visit(child)
        if ref != -1:
            parent_order.append(ref)
    visit(-1)
    output = bytearray(base.data[:32])
    struct.pack_into("<I", output, 20, len(parents))
    for item in base.chunks:
        body = item.body
        cid = u32(body) if item.tag in (b"INST", b"PROP") else None
        if item.tag == b"INST" and base.classes[cid][0] in SCRIPT_CLASSES:
            name, old_refs, service = base.classes[cid]
            need(service == 0, "Script class cannot be a service")
            ids = old_refs + additions[cid]
            body = struct.pack("<I", cid) + string(name.encode()) + b"\0" + struct.pack("<I", len(ids)) + refs(ids)
        elif item.tag == b"PROP" and base.classes[cid][0] in SCRIPT_CLASSES:
            _, name, kind, offset = property_header(body)
            old_refs = base.classes[cid][1]
            items = values(body[offset:], kind, len(old_refs))
            for ref in additions[cid]:
                items.append(default_property(name, kind, target_by_ref[ref]["path"], base.empty_shared_string))
            for i, ref in enumerate(old_refs + additions[cid]):
                target = target_by_ref[ref]
                if name == "Source":
                    items[i] = sources[target["file"]]
                elif name == "Name":
                    items[i] = target["path"].rsplit(".", 1)[-1].encode()
                elif name in ("Disabled", "RunContext"):
                    items[i] = bytes(1 if name == "Disabled" else 4)
            body = body[:offset] + encode_values(items, kind)
        elif item.tag == b"PRNT":
            body = b"\0" + struct.pack("<I", len(parents)) + refs(parent_order) + refs([parents[x] for x in parent_order])
        else:
            output.extend(item.raw)
            continue
        output.extend(chunk(item.tag, body))
    return bytes(output)
