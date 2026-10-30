import React from "react";
import {
  CanvasImage,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, clamp } from "./theme";
import {
  Headline,
  SceneFrame,
  TradeButton,
  sceneSchema,
  type SceneProps,
} from "./Elements";

const HookInner: React.FC<SceneProps> = ({ line1, line2, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <SceneFrame style={style}>
      <div
        style={{
          position: "absolute",
          top: 545,
          left: 0,
          width: 1080,
          height: 1130,
          overflow: "hidden",
          maskImage:
            "linear-gradient(transparent 0%,black 25%,black 72%,transparent 100%),linear-gradient(90deg,transparent,black 5%,black 95%,transparent)",
          maskComposite: "intersect",
        }}
      >
        <CanvasImage
          src={staticFile("assets/trader.png")}
          premountFor={fps}
          style={{
            position: "absolute",
            width: 2200,
            height: 1238,
            left: -580,
            top: -100,
            scale: interpolate(f, [0, 4.3 * fps], [1, 1.08], {
              ...clamp,
              output: "perceptual-scale",
            }),
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: 450,
            height: 500,
            background:
              "radial-gradient(ellipse at 0% 0%,#111334 45%,#111334ee 60%,transparent 76%)",
          }}
        />
      </div>
      <Headline
        line1={line1}
        line2={line2}
        premountFor={fps}
        style={{ fontSize: 109 }}
      />
      <Interactive.Div
        name="Opening question"
        premountFor={fps}
        style={{
          position: "absolute",
          top: 525,
          left: 84,
          fontFamily: "Arial",
          fontWeight: 700,
          fontSize: 44,
          opacity: interpolate(f, [0.45 * fps, 0.8 * fps], [0, 1], clamp),
        }}
      >
        Think you can read the market?
      </Interactive.Div>
      <Interactive.Div
        name="Buy or sell"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 100,
          right: 120,
          top: 1425,
          display: "flex",
          gap: 24,
          rotate: "-3deg",
          scale: interpolate(f, [0.7 * fps, 1.2 * fps], [0.7, 1], {
            ...clamp,
            output: "perceptual-scale",
          }),
          opacity: interpolate(f, [0.7 * fps, 0.9 * fps], [0, 1], clamp),
        }}
      >
        <TradeButton label="↑ BUY" color={C.green} />
        <TradeButton label="↓ SELL" color={C.red} />
      </Interactive.Div>
    </SceneFrame>
  );
};
export const HookScene = Interactive.withSchema({
  Component: HookInner,
  componentName: "<HookScene>",
  wrapInSequence: true,
  schema: sceneSchema,
});
