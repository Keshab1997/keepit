import type { Metadata } from "next";
import "./styles.css";
import "./dark-theme.css";
import "./pastel-theme.css";
import "./readability.css";
import "./image-upload.css";
import "./type-scale.css";

export const metadata: Metadata = {
  title: "KeepIt — Your visual second brain",
  description: "Save less. Remember more. A private home for everything worth keeping.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
