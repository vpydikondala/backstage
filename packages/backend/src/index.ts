import app from './app';

async function main() {
  const { backend } = await app();
  await backend.start();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
