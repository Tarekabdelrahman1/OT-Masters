import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';

function formatPrice(cents) {
  return `$${(cents / 100).toFixed(0)}`;
}

export default function ProductCard({ product }) {
  const { addItem } = useCart();

  return (
    <div className="product-card">
      <Link to={`/product/${product.slug}`}>
        <div className="product-media">
          {product.badge && <span className="tag-corner mono">{product.badge}</span>}
          <svg className="product-icon" viewBox="0 0 64 64" fill="none">
            <rect x="10" y="26" width="44" height="12" rx="2" fill="#7d8494" />
            <circle cx="14" cy="32" r="8" fill="#EDE9DF" />
            <circle cx="50" cy="32" r="8" fill="#EDE9DF" />
          </svg>
        </div>
      </Link>
      <div className="product-body">
        <Link to={`/product/${product.slug}`}>
          <div className="product-name">{product.name}</div>
        </Link>
        <div className="product-specs mono">
          {(product.spec_tags || []).map((tag) => (
            <span key={tag}>{tag}</span>
          ))}
        </div>
        <div className="product-footer">
          <span className="price">{formatPrice(product.price_cents)}</span>
          <button
            className="add-btn"
            aria-label={`Add ${product.name} to cart`}
            onClick={() => addItem(product, 1)}
          >
            +
          </button>
        </div>
      </div>
    </div>
  );
}
