import React from "react";
import {
  CanvasImage,
  Interactive,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { C, clamp } from "./theme";
import { SceneFrame, sceneSchema, type SceneProps } from "./Elements";

const EndInner: React.FC<SceneProps> = ({ line1, line2, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <SceneFrame style={style}>
      <div
        style={{
          position: "absolute",
          left: -200,
          top: 240,
          width: 1460,
          height: 1460,
          background:
            "repeating-conic-gradient(from 0deg,#6753dd18 0deg 7deg,transparent 7deg 20deg)",
          borderRadius: "50%",
          rotate: `${f * 0.1}deg`,
          maskImage: "radial-gradient(black,transparent 68%)",
        }}
      />
      <Interactive.Div
        name="Game icon"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 220,
          top: 300,
          width: 620,
          height: 620,
          borderRadius: 80,
          overflow: "hidden",
          border: "4px solid #5e9fff",
          boxShadow: "0 0 100px #6045ff70,0 35px 100px #0009",
          scale: interpolate(f, [0, 0.75 * fps], [0.6, 1], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
            output: "perceptual-scale",
          }),
          rotate: interpolate(f, [0, 1 * fps], ["-10deg", "0deg"], clamp),
        }}
      >
        <CanvasImage
          src={staticFile("assets/game-icon.png")}
          premountFor={fps}
          style={{ width: 620, height: 620 }}
        />
      </Interactive.Div>
      <Interactive.Div
        name="Closing headline"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 80,
          right: 110,
          top: 1005,
          textAlign: "center",
          fontSize: 94,
          lineHeight: 1.12,
          opacity: interpolate(f, [0.25 * fps, 0.6 * fps], [0, 1], clamp),
        }}
      >
        <div>{line1}</div>
        <div style={{ color: C.gold }}>{line2}</div>
      </Interactive.Div>
      <Interactive.Div
        name="Play on Roblox"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 155,
          right: 185,
          top: 1325,
          borderRadius: 28,
          background: C.gold,
          padding: "35px 20px",
          textAlign: "center",
          fontSize: 55,
          color: C.navy,
          boxShadow: "0 12px 0 #a66b20,0 25px 75px #ffce4033",
          scale: interpolate(f, [0.6 * fps, 1 * fps], [0.8, 1], {
            ...clamp,
            output: "perceptual-scale",
          }),
          opacity: interpolate(f, [0.6 * fps, 0.85 * fps], [0, 1], clamp),
        }}
      >
        PLAY ON ROBLOX <span style={{ fontFamily: "Arial" }}>↗</span>
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          top: 1515,
          left: 80,
          right: 110,
          textAlign: "center",
          fontSize: 38,
          color: C.muted,
          fontFamily: "Arial",
          fontWeight: 700,
        }}
      >
        Search “Get Funded!”
      </div>
    </SceneFrame>
  );
};
export const EndScene = Interactive.withSchema({
  Component: EndInner,
  componentName: "<EndScene>",
  wrapInSequence: true,
  schema: sceneSchema,
});
