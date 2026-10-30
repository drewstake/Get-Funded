import React from "react";
import {
  Interactive,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { C, clamp } from "./theme";
import {
  Badge,
  Headline,
  SceneFrame,
  sceneSchema,
  type SceneProps,
} from "./Elements";

const RankInner: React.FC<SceneProps> = ({ line1, line2, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <SceneFrame style={style}>
      <Headline line1={line1} line2={line2} premountFor={fps} />
      <div
        style={{
          position: "absolute",
          left: 84,
          top: 515,
          fontFamily: "Arial",
          fontSize: 44,
          color: C.muted,
          fontWeight: 700,
        }}
      >
        Earn titles. Climb the leaderboard.
      </div>
      <div
        style={{
          position: "absolute",
          left: 80,
          top: 690,
          width: 875,
          height: 880,
          background: "radial-gradient(ellipse,#8337ef66,transparent 65%)",
        }}
      />
      <Interactive.Div
        name="Market Rookie badge"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 98,
          top: 765,
          scale: interpolate(f, [0.25 * fps, 0.7 * fps], [0.2, 1], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
            output: "perceptual-scale",
          }),
          opacity: interpolate(f, [0.25 * fps, 0.5 * fps], [0, 1], clamp),
          rotate: "-9deg",
        }}
      >
        <Badge index={1} size={230} />
        <div
          style={{
            fontSize: 27,
            textAlign: "center",
            marginTop: 22,
            color: C.cyan,
          }}
        >
          MARKET ROOKIE
        </div>
      </Interactive.Div>
      <Interactive.Div
        name="Market Pro badge"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 661,
          top: 748,
          scale: interpolate(f, [0.65 * fps, 1.1 * fps], [0.2, 1], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
            output: "perceptual-scale",
          }),
          opacity: interpolate(f, [0.65 * fps, 0.85 * fps], [0, 1], clamp),
          rotate: "9deg",
        }}
      >
        <Badge index={11} size={240} />
        <div
          style={{
            fontSize: 29,
            textAlign: "center",
            marginTop: 22,
            color: C.gold,
          }}
        >
          MARKET PRO
        </div>
      </Interactive.Div>
      <Interactive.Div
        name="Trading Legend badge"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 295,
          top: 1030,
          scale: interpolate(f, [1.1 * fps, 1.8 * fps], [0.15, 1], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
            output: "perceptual-scale",
          }),
          opacity: interpolate(f, [1.1 * fps, 1.4 * fps], [0, 1], clamp),
          translate: `0px ${Math.sin(f / 15) * 8}px`,
          filter: "drop-shadow(0 0 48px #813cff99)",
        }}
      >
        <Badge index={15} size={460} />
      </Interactive.Div>
      <Interactive.Div
        name="Legend title"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 80,
          right: 110,
          top: 1530,
          textAlign: "center",
          color: C.gold,
          fontSize: 58,
          opacity: interpolate(f, [1.55 * fps, 1.95 * fps], [0, 1], clamp),
        }}
      >
        TRADING LEGEND
      </Interactive.Div>
    </SceneFrame>
  );
};
export const RankScene = Interactive.withSchema({
  Component: RankInner,
  componentName: "<RankScene>",
  wrapInSequence: true,
  schema: sceneSchema,
});
