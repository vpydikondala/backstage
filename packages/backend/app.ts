import { createBackend } from '@backstage/backend-defaults';
import { catalogPlugin } from '@backstage/plugin-catalog-backend';

export default async function main() {
  const backend = createBackend();
  backend.add(catalogPlugin());
  await backend.start();
}
