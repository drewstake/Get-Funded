import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { wipe } from "@remotion/transitions/wipe";
import { fade } from "@remotion/transitions/fade";
import { AbsoluteFill, staticFile, useVideoConfig } from "remotion";
import { HookScene } from "./HookScene";
import { StartScene } from "./StartScene";
import { TradeScene } from "./TradeScene";
import { RankScene } from "./RankScene";
import { EndScene } from "./EndScene";

export const GetFundedAd = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill>
      <Audio
        name="LONOWN & riserayss · worry (Slowed)"
        src={staticFile("audio/worry-slowed-20s.wav")}
        durationInFrames={20 * fps}
        premountFor={fps}
      />
      <TransitionSeries>
        <TransitionSeries.Sequence
          name="01 · Buy or sell?"
          durationInFrames={Math.round(4.1 * fps) + 8}
          premountFor={fps}
        >
          <HookScene
            line1="BUY OR SELL?"
            line2="YOUR CALL."
            premountFor={fps}
          />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={wipe({ direction: "from-right" })}
          timing={linearTiming({ durationInFrames: 8 })}
        />
        <TransitionSeries.Sequence
          name="02 · Starting balance"
          durationInFrames={Math.round(4.1 * fps) + 8}
          premountFor={fps}
        >
          <StartScene line1="START WITH" line2="$10,000." premountFor={fps} />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: 8 })}
        />
        <TransitionSeries.Sequence
          name="03 · Make your move"
          durationInFrames={Math.round(4.1 * fps) + 8}
          premountFor={fps}
        >
          <TradeScene line1="MAKE YOUR" line2="MOVE." premountFor={fps} />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={wipe({ direction: "from-left" })}
          timing={linearTiming({ durationInFrames: 8 })}
        />
        <TransitionSeries.Sequence
          name="04 · Climb the ranks"
          durationInFrames={Math.round(4.1 * fps) + 8}
          premountFor={fps}
        >
          <RankScene line1="FROM ROOKIE" line2="TO LEGEND." premountFor={fps} />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: 8 })}
        />
        <TransitionSeries.Sequence
          name="05 · Play Get Funded!"
          durationInFrames={Math.round(3.6 * fps)}
          premountFor={fps}
        >
          <EndScene line1="THE MARKET" line2="IS YOURS." premountFor={fps} />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </AbsoluteFill>
  );
};
