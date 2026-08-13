import { createMDX } from 'fumadocs-mdx/next';

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  allowedDevOrigins: ['127.0.0.1'],
  async rewrites() {
    return [
      {
        source: '/docs.mdx',
        destination: '/llms.mdx/docs',
      },
      {
        source: '/docs/:path*.mdx',
        destination: '/llms.mdx/docs/:path*',
      },
    ];
  },
};

const withMDX = createMDX({
  configPath: './source.config.ts',
});

export default withMDX(config);
