import { createBackend } from '@backstage/backend-defaults';

export default async function app() {
  const backend = createBackend();
  // register plugins here as needed
  return { backend };
}
