import { defineConfig } from 'vitest/config';

// Pure utility functions only — no DOM required, so run in the node environment.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
