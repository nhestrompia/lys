import { LysLogo } from '@/components/lys-logo';
import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span className="lys-nav-title">
          <LysLogo />
          <span>
            <strong>Lys</strong>
            <small>Documentation</small>
          </span>
        </span>
      ),
    },
    githubUrl: 'https://github.com/nhestrompia/lys',
    themeSwitch: {
      enabled: false,
    },
  };
}
