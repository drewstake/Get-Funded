import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Easing,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  type InteractivitySchema,
} from "remotion";
import { C, clamp, font } from "./theme";

export const SceneFrame: React.FC<{
  children: React.ReactNode;
  style?: React.CSSProperties;
  glow?: string;
}> = ({ children, style, glow = C.purple }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        background: C.navy,
        color: C.white,
        fontFamily: font,
        overflow: "hidden",
        ...style,
      }}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse at 70% 30%, ${glow}39 0%, transparent 62%), radial-gradient(ellipse at 10% 90%, #0453ad88, transparent 60%)`,
        }}
      />
      <AbsoluteFill
        style={{
          opacity: 0.15,
          backgroundImage:
            "linear-gradient(#6a98cf 1px, transparent 1px),linear-gradient(90deg,#6a98cf 1px,transparent 1px)",
          backgroundSize: "90px 90px",
          translate: `0px ${f * 0.2}px`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 80,
          right: 110,
          top: 108,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          fontSize: 30,
          letterSpacing: 2,
        }}
      >
        <span style={{ color: C.gold }}>GET FUNDED!</span>
        <span
          style={{
            fontFamily: "Arial",
            fontSize: 24,
            fontWeight: 800,
            letterSpacing: 4,
            color: C.muted,
          }}
        >
          ON ROBLOX
        </span>
      </div>
      {children}
      <div
        style={{
          position: "absolute",
          left: 80,
          bottom: 156,
          color: "#b7c7ed",
          fontFamily: "Arial",
          fontWeight: 600,
          fontSize: 25,
          letterSpacing: 1,
        }}
      >
        TRADING SIMULATOR · VIRTUAL CURRENCY
      </div>
    </AbsoluteFill>
  );
};

type HeadlineProps = {
  line1: string;
  line2: string;
  accent?: string;
  style?: React.CSSProperties;
};
const HeadlineInner: React.FC<HeadlineProps> = ({
  line1,
  line2,
  accent = C.gold,
  style,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Interactive.Div
      name="Headline"
      premountFor={fps}
      style={{
        position: "absolute",
        top: 255,
        left: 80,
        right: 90,
        fontSize: 104,
        lineHeight: 1.04,
        letterSpacing: -2,
        textShadow: "0 7px 0 #030721, 0 14px 36px #0007",
        ...style,
      }}
    >
      <div
        style={{
          translate: interpolate(f, [0, 0.5 * fps], ["0px 70px", "0px 0px"], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          opacity: interpolate(f, [0, 0.25 * fps], [0, 1], clamp),
        }}
      >
        {line1}
      </div>
      <div
        style={{
          color: accent,
          translate: interpolate(
            f,
            [0.14 * fps, 0.7 * fps],
            ["0px 85px", "0px 0px"],
            { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) },
          ),
          opacity: interpolate(f, [0.14 * fps, 0.35 * fps], [0, 1], clamp),
        }}
      >
        {line2}
      </div>
    </Interactive.Div>
  );
};
export const Headline = Interactive.withSchema({
  Component: HeadlineInner,
  componentName: "<Headline>",
  wrapInSequence: true,
  schema: {
    line1: { type: "text-content", default: "", description: "First line" },
    line2: { type: "text-content", default: "", description: "Accent line" },
    accent: { type: "color", default: C.gold, description: "Accent color" },
  } as const satisfies InteractivitySchema,
});

export const Badge: React.FC<{ index: number; size: number }> = ({
  index,
  size,
}) => {
  const { fps } = useVideoConfig();
  const row = Math.floor((index - 1) / 4);
  const col = (index - 1) % 4;
  const tops = [0, 251, 499, 738];
  const heights = [251, 248, 239, 286];
  return (
    <div
      style={{
        width: size,
        height: size,
        position: "relative",
        overflow: "hidden",
      }}
    >
      <CanvasImage
        src={staticFile("assets/ranks.png")}
        premountFor={fps}
        style={{
          position: "absolute",
          width: size * 4,
          height: (size * 1024) / heights[row],
          left: -col * size,
          top: (-tops[row] * size) / heights[row],
        }}
      />
    </div>
  );
};

export const sceneSchema = {
  line1: { type: "text-content", default: "", description: "Headline" },
  line2: { type: "text-content", default: "", description: "Accent headline" },
} as const satisfies InteractivitySchema;
export type SceneProps = {
  line1: string;
  line2: string;
  style?: React.CSSProperties;
};

export const TradeButton: React.FC<{
  label: string;
  color: string;
  active?: boolean;
}> = ({ label, color, active }) => (
  <div
    style={{
      flex: 1,
      borderRadius: 22,
      border: `3px solid ${color}`,
      background: `linear-gradient(${color}, ${color}90)`,
      boxShadow: active
        ? `0 0 50px ${color}60, 0 9px 0 #020b32`
        : "0 9px 0 #020b32",
      textAlign: "center",
      padding: "24px 10px",
      color: "#071633",
      fontSize: 50,
    }}
  >
    {label}
  </div>
);
