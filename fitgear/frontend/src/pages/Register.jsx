import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

export default function Register() {
  const { register } = useAuth();
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await register(name, email, password);
      navigate('/');
    } catch (err) {
      setError(err.response?.data?.error || 'Could not create account. Try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="form-shell">
      <div className="section-tag">Join The Rack</div>
      <h1 className="page-title display" style={{ fontSize: 36, marginBottom: 32 }}>Create Account</h1>

      {error && <div className="form-error">{error}</div>}

      <form onSubmit={handleSubmit}>
        <div className="form-field">
          <label htmlFor="name">Name</label>
          <input id="name" type="text" value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <div className="form-field">
          <label htmlFor="email">Email</label>
          <input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </div>
        <div className="form-field">
          <label htmlFor="password">Password</label>
          <input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} minLength={8} required />
        </div>
        <button className="btn-primary" style={{ width: '100%' }} type="submit" disabled={loading}>
          {loading ? 'Creating Account…' : 'Create Account'}
        </button>
      </form>

      <p className="form-note">
        Already have an account? <Link to="/login" style={{ color: 'var(--load)' }}>Sign in</Link>
      </p>
    </div>
  );
}
