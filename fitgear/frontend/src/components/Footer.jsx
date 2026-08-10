export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="footer-inner">
        <div className="footer-brand">
          <div className="logo"><span className="plate"></span>FITGEAR</div>
          <p>Equipment for the gym you build yourself. Iron, rubber and steel — nothing that needs a plug.</p>
        </div>
        <div className="footer-col">
          <h4>Shop</h4>
          <a href="/shop?category=free-weights">Free Weights</a>
          <a href="/shop?category=resistance">Resistance</a>
          <a href="/shop?category=cardio">Cardio</a>
          <a href="/shop">All Products</a>
        </div>
        <div className="footer-col">
          <h4>Support</h4>
          <a href="#">Shipping</a>
          <a href="#">Returns</a>
          <a href="#">Size &amp; Load Guide</a>
          <a href="#">Contact</a>
        </div>
        <div className="footer-col">
          <h4>Company</h4>
          <a href="#">About</a>
          <a href="#">Reviews</a>
          <a href="#">Wholesale</a>
        </div>
      </div>
      <div className="footer-bottom">
        <span>© 2026 FITGEAR SUPPLY CO.</span>
        <span>RACKED IN THE USA</span>
      </div>
    </footer>
  );
}
