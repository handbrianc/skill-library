const { greet, add } = require('../src/index');

describe('greet', () => {
  it('returns greeting with name', () => {
    if (greet('World') !== 'Hello, World!') {
      throw new Error('Expected Hello, World!');
    }
  });
});

describe('add', () => {
  it('adds two numbers', () => {
    if (add(2, 3) !== 5) {
      throw new Error('Expected 5');
    }
  });

  it('handles negative numbers', () => {
    if (add(-1, 1) !== 0) {
      throw new Error('Expected 0');
    }
  });
});
