import { Link } from 'react-router-dom';

export default function CategoryPlates({ categories }) {
  if (!categories || categories.length === 0) return null;

  return (
    <div className="plates-row">
      {categories.map((c) => (
        <Link to={`/shop?category=${c.slug}`} className="plate-card" key={c.id}>
          <div className="plate-weight mono">{c.plate_label}</div>
          <div className="plate-name">{c.name}</div>
          <div className="plate-desc">{c.description}</div>
        </Link>
      ))}
    </div>
  );
}
