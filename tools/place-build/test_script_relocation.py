"""In-memory checks for the client lifecycle entry-point relocation; no place saves."""
import copy
import unittest

import build
from rbxl import Place, overlay


class ScriptRelocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest, cls.sources, cls.base, _ = build.load_inputs()

    def test_relocation_preserves_script_identity_and_scene(self):
        place = Place(overlay(self.base, self.manifest["scripts"], self.sources))
        build.verify_binary(place, self.manifest, self.sources, self.base)
        old = self.base.resolve("StarterGui.MarketReign.TradingClient")
        self.assertEqual(place.resolve("StarterPlayer.StarterPlayerScripts.TradingClient"), old)
        self.assertNotIn("StarterGui.MarketReign.TradingClient", [place.path(r) for r in place.scripts()])

    def test_move_requires_explicit_manifest_declaration(self):
        entries = copy.deepcopy(self.manifest["scripts"])
        for item in entries:
            item.pop("previousPath", None)
        with self.assertRaisesRegex(ValueError, "Unexpected or duplicate script"):
            overlay(self.base, entries, self.sources)

    def test_duplicate_original_path_is_rejected(self):
        entries = copy.deepcopy(self.manifest["scripts"])
        entries[0]["previousPath"] = "StarterGui.MarketReign.TradingClient"
        with self.assertRaisesRegex(ValueError, "Duplicate script target or relocation"):
            overlay(self.base, entries, self.sources)

    def test_player_scripts_cannot_require_server_modules(self):
        entries = [
            {"path": "StarterPlayer.StarterPlayerScripts.Client", "class": "LocalScript", "file": "client"},
            {"path": "ServerScriptService.Secret", "class": "ModuleScript", "file": "server"},
        ]
        with self.assertRaisesRegex(ValueError, "Client requires server-only module"):
            build.validate_dependencies(entries, {
                "client": b"local secret = require(game.ServerScriptService.Secret)",
                "server": b"return {}",
            })


if __name__ == "__main__":
    unittest.main()
