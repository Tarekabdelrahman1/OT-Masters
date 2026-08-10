import { createContext, useContext, useState } from 'react';
import client from '../api/client';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => {
    try {
      const stored = localStorage.getItem('fitgear_user');
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
  });

  function persist(user, token) {
    localStorage.setItem('fitgear_user', JSON.stringify(user));
    localStorage.setItem('fitgear_token', token);
    setUser(user);
  }

  async function login(email, password) {
    const { data } = await client.post('/auth/login', { email, password });
    persist(data.user, data.token);
  }

  async function register(name, email, password) {
    const { data } = await client.post('/auth/register', { name, email, password });
    persist(data.user, data.token);
  }

  function logout() {
    localStorage.removeItem('fitgear_user');
    localStorage.removeItem('fitgear_token');
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, login, register, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider');
  return ctx;
}
