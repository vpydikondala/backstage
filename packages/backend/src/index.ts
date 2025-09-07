import app from './app';

app().catch(err => {
  console.error('Backend failed to start:', err);
  process.exit(1);
});
