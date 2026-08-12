import '@/app/global.css';
import { RootProvider } from 'fumadocs-ui/provider/next';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: {
    default: 'Lys documentation',
    template: '%s · Lys documentation',
  },
  description:
    'Install Lys and integrate its semantic testing SDK with React Native, Expo, SwiftUI, or UIKit.',
  metadataBase: new URL('https://github.com/nhestrompia/lys'),
};

const designContract = `<!--
THESIS: A vertical proof ledger turns SDK setup into an auditable path and refuses the generic documentation dashboard.
OWN-WORLD: Luminous cool-gray canvas, opaque white working surfaces, native blue agency, quiet separators, compact system type, and literal code.
STORY: Understand Lys, install it, instrument real controls, export a validated contract, then give agents machine-readable implementation guidance.
FIRST VIEWPORT: Fixed navigation frames a narrow reading column whose blue route line connects installation, instrumentation, export, and evidence.
FORM: Vertical implementation ledger, selected composition B, seed aeda4efb.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, and DESIGN.md
-->`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex min-h-screen flex-col antialiased">
        <span
          aria-hidden="true"
          className="design-contract"
          dangerouslySetInnerHTML={{ __html: designContract }}
        />
        <RootProvider theme={{ enabled: false }}>{children}</RootProvider>
      </body>
    </html>
  );
}
