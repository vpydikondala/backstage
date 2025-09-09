// packages/backend/src/index.ts
import { createBackend } from '@backstage/backend-defaults';

async function main() {
  const backend = createBackend();
  await backend.start();  // uses standard service builder under the hood
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
