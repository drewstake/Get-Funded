import React from "react";
import {
  Interactive,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";
import { C, clamp } from "./theme";
import { Chart, chartState } from "./Chart";
import { Headline, SceneFrame, sceneSchema, type SceneProps } from "./Elements";

const TradeInner: React.FC<SceneProps> = ({ line1, line2, style }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const profit = (chartState(f, fps, "trade").price - 5825) * 50;
  const closed = f >= 2.8 * fps;
  return (
    <SceneFrame style={style} glow={C.green}>
      <Headline
        line1={line1}
        line2={line2}
        accent={C.green}
        premountFor={fps}
      />
      <div
        style={{
          position: "absolute",
          top: 575,
          left: 80,
          right: 105,
          textAlign: "center",
        }}
      >
        <div
          style={{
            fontFamily: "Arial",
            fontSize: 28,
            fontWeight: 800,
            letterSpacing: 4,
            color: C.muted,
          }}
        >
          {closed ? "TRADE CLOSED" : "OPEN GAIN / LOSS"}
        </div>
        <Interactive.Div
          name="Trade result"
          premountFor={fps}
          style={{
            fontSize: 144,
            letterSpacing: -5,
            color: profit < 0 ? C.red : C.green,
            marginTop: 10,
            textShadow: `0 0 50px ${profit < 0 ? C.red : C.green}55`,
            scale: interpolate(
              f,
              [2.8 * fps, 3.05 * fps, 3.3 * fps],
              [1, 1.1, 1],
              clamp,
            ),
          }}
        >
          {profit < 0 ? "−" : "+"}$
          {Math.abs(profit).toLocaleString("en-US", {
            maximumFractionDigits: 2,
          })}
        </Interactive.Div>
        <div style={{ fontFamily: "Arial", fontSize: 30, color: C.muted }}>
          1 BX CONTRACT · VIRTUAL PROFIT
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 70,
          top: 910,
          width: 910,
          padding: "28px 24px",
          boxSizing: "border-box",
          borderRadius: 28,
          background: "#0b204b",
          border: "2px solid #28507a",
        }}
      >
        <Chart phase="trade" compact />
      </div>
      <Interactive.Div
        name="Close confirmation"
        premountFor={fps}
        style={{
          position: "absolute",
          top: 1430,
          left: 90,
          right: 120,
          background: closed ? C.green : "#14365a",
          border: `3px solid ${C.green}`,
          borderRadius: 26,
          padding: "28px 30px",
          textAlign: "center",
          color: closed ? C.navy : C.white,
          boxShadow: closed ? `0 0 60px ${C.green}35` : "none",
          scale: interpolate(f, [2.8 * fps, 3.15 * fps], [0.94, 1], {
            ...clamp,
            easing: Easing.bezier(0.2, 1, 0.3, 1),
            output: "perceptual-scale",
          }),
        }}
      >
        <div style={{ fontSize: 44 }}>
          {closed ? "✓ PROFIT LOCKED IN" : "WATCH THE NEXT CANDLE"}
        </div>
        <div
          style={{
            fontFamily: "Arial",
            fontSize: 29,
            fontWeight: 800,
            marginTop: 10,
          }}
        >
          {closed ? "NEW BALANCE  $11,500" : "BUY · MANAGE · CLOSE"}
        </div>
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          top: 1634,
          left: 80,
          right: 110,
          textAlign: "center",
          fontFamily: "Arial",
          fontSize: 22,
          color: C.muted,
        }}
      >
        STAGED EXAMPLE · RESULTS VARY
      </div>
    </SceneFrame>
  );
};
export const TradeScene = Interactive.withSchema({
  Component: TradeInner,
  componentName: "<TradeScene>",
  wrapInSequence: true,
  schema: sceneSchema,
});
