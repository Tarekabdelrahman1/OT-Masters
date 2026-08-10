import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import ProductCard from '../components/ProductCard';
import client from '../api/client';

export default function Shop() {
  const [searchParams, setSearchParams] = useSearchParams();
  const category = searchParams.get('category') || '';
  const [categories, setCategories] = useState([]);
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    client.get('/products/categories').then((res) => setCategories(res.data)).catch(() => {});
  }, []);

  useEffect(() => {
    setLoading(true);
    const query = category ? `?category=${category}` : '';
    client
      .get(`/products${query}`)
      .then((res) => setProducts(res.data))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [category]);

  return (
    <>
      <div className="page-head">
        <div className="section-tag">Full Catalog</div>
        <h1 className="page-title display">The Shop</h1>
      </div>

      <div className="wrap" style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginBottom: 40 }}>
        <button
          className={category === '' ? 'btn-primary' : 'btn-ghost'}
          onClick={() => setSearchParams({})}
        >
          All
        </button>
        {categories.map((c) => (
          <button
            key={c.id}
            className={category === c.slug ? 'btn-primary' : 'btn-ghost'}
            onClick={() => setSearchParams({ category: c.slug })}
          >
            {c.name}
          </button>
        ))}
      </div>

      <section className="section" style={{ paddingTop: 0 }}>
        {loading ? (
          <div className="loading-state">LOADING GEAR…</div>
        ) : products.length === 0 ? (
          <div className="empty-state">No gear in this category yet. Check back soon.</div>
        ) : (
          <div className="product-grid">
            {products.map((p) => (
              <ProductCard product={p} key={p.id} />
            ))}
          </div>
        )}
      </section>
    </>
  );
}
