declare namespace NodeJS {
  interface ProcessEnv {
    // Keep the statically named access for Next's public build-time substitution.
    readonly NEXT_PUBLIC_API_URL?: string;
  }
}
