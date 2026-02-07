import { render, screen } from '@testing-library/react';
import App from './App';

test('renders the bookstore app', () => {
  render(<App />);
  // Verify the app renders without crashing
  expect(document.querySelector('.App')).toBeInTheDocument();
});
