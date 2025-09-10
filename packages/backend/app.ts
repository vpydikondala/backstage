import { createBackend } from '@backstage/backend-defaults';

export default async function app() {
  const backend = createBackend();
  // Register plugins here later, e.g. catalog, auth, etc.
  return { backend };
}
