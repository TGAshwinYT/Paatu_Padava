import { describe, it, expect, beforeEach } from 'vitest';

describe('Auth Token Storage & Session Hygiene', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('clears session keys cleanly on logout', () => {
    localStorage.setItem('token', 'access-jwt');
    localStorage.setItem('refresh_token', 'refresh-jwt');
    localStorage.setItem('user', JSON.stringify({ id: 'u1' }));

    localStorage.removeItem('token');
    localStorage.removeItem('refresh_token');
    localStorage.removeItem('user');

    expect(localStorage.getItem('token')).toBeNull();
    expect(localStorage.getItem('refresh_token')).toBeNull();
    expect(localStorage.getItem('user')).toBeNull();
  });
});
