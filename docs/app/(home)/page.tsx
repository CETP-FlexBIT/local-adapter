import Link from 'next/link';

export default function HomePage() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col justify-center px-6 py-20">
      <p className="mb-4 text-sm font-medium text-fd-muted-foreground">
        Edge telemetry adapter
      </p>
      <h1 className="max-w-3xl text-4xl font-semibold tracking-tight sm:text-6xl">
        FlexBIT Local Adapter
      </h1>
      <p className="mt-6 max-w-2xl text-lg leading-8 text-fd-muted-foreground">
        Install the adapter, map your device fields, and send telemetry to FlexBIT.
      </p>
      <div className="mt-10 flex flex-wrap gap-3">
        <Link
          href="/docs/installation"
          className="rounded-lg bg-fd-primary px-5 py-3 text-sm font-medium text-fd-primary-foreground"
        >
          Installation
        </Link>
        <Link
          href="/docs/how-it-works"
          className="rounded-lg border px-5 py-3 text-sm font-medium"
        >
          How it works
        </Link>
      </div>
    </main>
  );
}
