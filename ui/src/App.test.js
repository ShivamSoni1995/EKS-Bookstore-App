import { render } from '@testing-library/react';
import App from './App';

test('renders the bookstore app without crashing', () => {
  const { container } = render(<App />);
  expect(container.querySelector('.App')).toBeTruthy();
});
