import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { C, clamp } from "./theme";

// A staged BX move. One contract gains $50/point: 5,825 to 5,855 = +$1,500.
const closes = [
  5807, 5810, 5809, 5815, 5813, 5818, 5823, 5820, 5825, 5822, 5828, 5825, 5821,
  5818, 5822, 5828, 5831, 5827, 5834, 5837, 5832, 5839, 5843, 5840, 5847, 5844,
  5851, 5855,
];
export const chartState = (
  frame: number,
  fps: number,
  phase: "setup" | "trade",
) => {
  const shown =
    phase === "setup"
      ? interpolate(frame, [0, 2.3 * fps], [8, 12], clamp)
      : interpolate(frame, [0, 2.6 * fps], [12, 28], clamp);
  const count = Math.min(28, Math.ceil(shown));
  const i = count - 1;
  const open = i === 0 ? 5804 : closes[i - 1];
  const price =
    Math.round((open + (closes[i] - open) * Math.max(0.1, shown - i)) * 4) / 4;
  return { shown, count, price };
};
export const Chart: React.FC<{
  phase?: "setup" | "trade";
  compact?: boolean;
}> = ({ phase = "setup", compact = false }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { shown, count, price } = chartState(f, fps, phase);
  const h = compact ? 420 : 570;
  const y = (p: number) => h - 40 - ((p - 5800) / 65) * (h - 75);
  const last = price;
  return (
    <svg
      viewBox={`0 0 850 ${h}`}
      style={{ width: "100%", height: h, overflow: "visible" }}
    >
      {[5805, 5820, 5835, 5850].map((p) => (
        <g key={p}>
          <line
            x1="12"
            x2="742"
            y1={y(p)}
            y2={y(p)}
            stroke="#26426e"
            strokeWidth="2"
            strokeDasharray="5 9"
          />
          <text
            x="762"
            y={y(p) + 6}
            fill="#9bafce"
            fontSize="21"
            fontFamily="Arial"
          >
            {p.toLocaleString("en-US")}
          </text>
        </g>
      ))}
      {closes.slice(0, count).map((close, i) => {
        const open = i === 0 ? 5804 : closes[i - 1];
        const color = close >= open ? C.green : C.red;
        const progress = i === count - 1 ? Math.max(0.1, shown - i) : 1;
        const current = Math.round((open + (close - open) * progress) * 4) / 4;
        const x = 22 + i * 25.5;
        return (
          <g key={i}>
            <line
              x1={x + 7}
              x2={x + 7}
              y1={y(Math.max(open, current) + 1.5 + (i % 3) * 0.5)}
              y2={y(Math.min(open, current) - 1.5)}
              stroke={color}
              strokeWidth="3"
            />
            <rect
              x={x}
              y={Math.min(y(open), y(current))}
              width="14"
              height={Math.max(4, Math.abs(y(open) - y(current)))}
              rx="2"
              fill={color}
            />
          </g>
        );
      })}
      <line
        x1="12"
        x2="742"
        y1={y(5825)}
        y2={y(5825)}
        stroke={C.cyan}
        strokeWidth="2"
        strokeDasharray="10 10"
      />
      <rect
        x="20"
        y={y(5825) - 35}
        width="172"
        height="31"
        rx="6"
        fill="#13466b"
      />
      <text
        x="33"
        y={y(5825) - 13}
        fill={C.cyan}
        fontSize="19"
        fontFamily="Arial"
        fontWeight="bold"
      >
        BUY 1 · 5,825
      </text>
      <line
        x1={22 + (count - 1) * 25.5}
        x2="741"
        y1={y(last)}
        y2={y(last)}
        stroke={C.green}
        strokeWidth="2"
        strokeDasharray="5 6"
        opacity={0.75}
      />
      <circle cx={29 + (count - 1) * 25.5} cy={y(last)} r="6" fill={C.white} />
    </svg>
  );
};
