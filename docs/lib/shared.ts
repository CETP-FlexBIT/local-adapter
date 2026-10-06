export const appName = 'FlexBIT Local Adapter';
export const siteBasePath = process.env.NEXT_PUBLIC_BASE_PATH || '';
export const docsRoute = '/docs';
export const docsImageRoute = '/og/docs';
export const docsContentRoute = '/llms.mdx/docs';

export function withSiteBasePath(path: string) {
  return `${siteBasePath}${path}`;
}

export const gitConfig = {
  user: 'CETP-FlexBIT',
  repo: 'local-adapter',
  branch: 'main',
};
