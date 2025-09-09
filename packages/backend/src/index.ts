import backend from './app';

backend.start().catch(err => {
  console.error(err);
  process.exit(1);
});
