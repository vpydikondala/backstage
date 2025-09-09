import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Minimal set; add more plugins as you need them
backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-catalog-backend'));
// Example, only if you plan to use K8s features
// backend.add(import('@backstage/plugin-kubernetes-backend'));

export default backend;
