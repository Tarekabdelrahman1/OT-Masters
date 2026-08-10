import { Link, NavLink } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';

export default function Navbar() {
  const { count } = useCart();
  const { user, logout } = useAuth();

  return (
    <nav className="site-nav">
      <div className="nav-inner">
        <Link to="/" className="logo">
          <span className="plate"></span>FITGEAR
        </Link>
        <div className="nav-links">
          <NavLink to="/shop" className={({ isActive }) => (isActive ? 'active' : '')}>
            Shop
          </NavLink>
          <NavLink to="/cart" className={({ isActive }) => (isActive ? 'active' : '')}>
            Cart{count > 0 && <span className="cart-count mono">{count}</span>}
          </NavLink>
          {user ? (
            <a href="#" onClick={(e) => { e.preventDefault(); logout(); }}>
              Sign Out
            </a>
          ) : (
            <NavLink to="/login" className={({ isActive }) => (isActive ? 'active' : '')}>
              Sign In
            </NavLink>
          )}
        </div>
        <Link to="/shop" className="nav-cta">
          Shop Now
        </Link>
      </div>
    </nav>
  );
}
