import React from 'react';
import { render } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';

// Mock fetch to prevent API calls during tests
global.fetch = jest.fn(() =>
  Promise.resolve({
    json: () => Promise.resolve([]),
  })
);

test('renders the bookstore app without crashing', async () => {
  const App = require('./App').default;
  const { container } = render(<App />);
  expect(container.querySelector('.App')).toBeTruthy();
});
