import { Provider } from '@/components/provider';
import './global.css';

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}

export const metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'),
  title: {
    default: 'FlexBIT Local Adapter',
    template: '%s | FlexBIT Local Adapter',
  },
  description: 'Installation and operations documentation for FlexBIT Local Adapter.',
};
