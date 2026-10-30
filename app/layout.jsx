import "./globals.css";
import AuthGate from "./components/AuthGate";
export const metadata = {
  title: "MY DERBY | 마이더비",
  description: "가상의 경마 세계에서 최고의 마주가 되어보세요.",
  viewport: "width=device-width, initial-scale=1",
};
export default function RootLayout({ children }) {
  return <html lang="ko"><body><AuthGate>{children}</AuthGate></body></html>;
}
