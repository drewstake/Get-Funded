import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

loadFont({
  family: "Fredoka",
  url: staticFile("fonts/FredokaOne-Regular.ttf"),
});

export const C = {
  navy: "#070d2c",
  blue: "#102665",
  purple: "#8148ff",
  cyan: "#42dcff",
  gold: "#ffda59",
  green: "#39efae",
  red: "#ff5681",
  white: "#f8fbff",
  muted: "#b7c7ed",
};
export const font = "Fredoka, Arial, sans-serif";
export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;
