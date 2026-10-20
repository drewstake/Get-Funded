import React from "react";
import {
  Interactive,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { C, clamp } from "./theme";
import { Chart } from "./Chart";
import {
  Headline,
  SceneFrame,
  TradeButton,
  sceneSchema,
  type SceneProps,
} from "./Elements";

const StartInner: React.FC<SceneProps> = ({ line1, line2, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <SceneFrame style={style} glow={C.cyan}>
      <Headline line1={line1} line2={line2} premountFor={fps} />
      <div
        style={{
          position: "absolute",
          left: 84,
          top: 508,
          fontFamily: "Arial",
          fontSize: 42,
          color: C.muted,
          fontWeight: 700,
        }}
      >
        Your starting balance. Your next move.
      </div>
      <Interactive.Div
        name="Trading terminal"
        premountFor={fps}
        style={{
          position: "absolute",
          left: 70,
          top: 660,
          width: 910,
          borderRadius: 34,
          border: `3px solid ${C.cyan}70`,
          background: "linear-gradient(145deg,#102b61,#071439)",
          padding: 28,
          boxSizing: "border-box",
          boxShadow: "0 35px 100px #0009",
          translate: interpolate(f, [0, 0.7 * fps], ["0px 180px", "0px 0px"], {
            ...clamp,
            easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            paddingBottom: 26,
            borderBottom: "2px solid #345089",
          }}
        >
          <span style={{ fontSize: 37 }}>
            BLOX 500 <span style={{ fontSize: 24, color: C.cyan }}>BX</span>
          </span>
          <span style={{ color: C.green, fontSize: 27 }}>● MARKET OPEN</span>
        </div>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 25,
            color: C.muted,
            marginTop: 28,
          }}
        >
          <span>ACCOUNT BALANCE</span>
          <span>VIRTUAL FUNDS</span>
        </div>
        <div style={{ fontSize: 78, color: C.gold, margin: "7px 0 18px" }}>
          $10,000
        </div>
        <Chart />
        <div style={{ display: "flex", gap: 22, marginTop: 15 }}>
          <TradeButton label="↑ BUY" color={C.green} active={f > 2 * fps} />
          <TradeButton label="↓ SELL" color={C.red} />
        </div>
        <div
          style={{
            fontFamily: "Arial",
            fontSize: 23,
            color: C.muted,
            textAlign: "center",
            marginTop: 27,
          }}
        >
          ANIMATED GAMEPLAY DEMO
        </div>
      </Interactive.Div>
    </SceneFrame>
  );
};
export const StartScene = Interactive.withSchema({
  Component: StartInner,
  componentName: "<StartScene>",
  wrapInSequence: true,
  schema: sceneSchema,
});
