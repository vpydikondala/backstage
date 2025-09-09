import React from 'react';
import { createRoot } from 'react-dom/client';
import { createApp } from '@backstage/app-defaults';

const app = createApp();
const App = app.getProvider();

const root = createRoot(document.getElementById('root')!);
root.render(<App />);
