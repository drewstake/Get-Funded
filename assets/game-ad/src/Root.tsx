import { Composition, Folder } from "remotion";
import { GetFundedAd } from "./GetFundedAd";
import { HookScene } from "./HookScene";
import { StartScene } from "./StartScene";
import { TradeScene } from "./TradeScene";
import { RankScene } from "./RankScene";
import { EndScene } from "./EndScene";

export const RemotionRoot = () => (
  <>
    <Composition
      id="GetFunded-Ad"
      component={GetFundedAd}
      width={1080}
      height={1920}
      fps={30}
      durationInFrames={600}
    />
    <Folder name="Scenes">
      <Composition
        id="Hook"
        component={HookScene}
        width={1080}
        height={1920}
        fps={30}
        durationInFrames={131}
        defaultProps={{ line1: "BUY OR SELL?", line2: "YOUR CALL." }}
      />
      <Composition
        id="Starting-Balance"
        component={StartScene}
        width={1080}
        height={1920}
        fps={30}
        durationInFrames={131}
        defaultProps={{ line1: "START WITH", line2: "$10,000." }}
      />
      <Composition
        id="Make-Your-Move"
        component={TradeScene}
        width={1080}
        height={1920}
        fps={30}
        durationInFrames={131}
        defaultProps={{ line1: "MAKE YOUR", line2: "MOVE." }}
      />
      <Composition
        id="Rank-Up"
        component={RankScene}
        width={1080}
        height={1920}
        fps={30}
        durationInFrames={131}
        defaultProps={{ line1: "FROM ROOKIE", line2: "TO LEGEND." }}
      />
      <Composition
        id="Play-on-Roblox"
        component={EndScene}
        width={1080}
        height={1920}
        fps={30}
        durationInFrames={108}
        defaultProps={{ line1: "THE MARKET", line2: "IS YOURS." }}
      />
    </Folder>
  </>
);
