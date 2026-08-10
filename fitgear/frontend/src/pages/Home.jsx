import { useEffect, useState } from 'react';
import Hero from '../components/Hero';
import MarqueeStrip from '../components/MarqueeStrip';
import CategoryPlates from '../components/CategoryPlates';
import ProductCard from '../components/ProductCard';
import BundleBanner from '../components/BundleBanner';
import client from '../api/client';

export default function Home() {
  const [categories, setCategories] = useState([]);
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([client.get('/products/categories'), client.get('/products')])
      .then(([catRes, prodRes]) => {
        setCategories(catRes.data);
        setProducts(prodRes.data.slice(0, 6));
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <>
      <Hero />
      <MarqueeStrip />

      <section className="section" id="racks">
        <div className="section-head">
          <div>
            <div className="section-tag">Shop by Category</div>
            <h2 className="section-title display">Pick Your Discipline</h2>
          </div>
          <p className="section-note">
            Four ways to load a home gym — strength, conditioning, mobility, or all three stacked in one rack.
          </p>
        </div>
        {loading ? (
          <div className="loading-state">LOADING CATEGORIES…</div>
        ) : (
          <CategoryPlates categories={categories} />
        )}
      </section>

      <section className="section" id="products" style={{ background: 'var(--iron-2)', borderTop: '1px solid var(--line)', borderBottom: '1px solid var(--line)' }}>
        <div className="section-head">
          <div>
            <div className="section-tag">Best Sellers</div>
            <h2 className="section-title display">Straight Off The Rack</h2>
          </div>
          <p className="section-note">
            Six pieces of gear customers reorder most. Sorted by what actually gets used.
          </p>
        </div>
        {loading ? (
          <div className="loading-state">LOADING GEAR…</div>
        ) : (
          <div className="product-grid">
            {products.map((p) => (
              <ProductCard product={p} key={p.id} />
            ))}
          </div>
        )}
      </section>

      <BundleBanner />
    </>
  );
}
