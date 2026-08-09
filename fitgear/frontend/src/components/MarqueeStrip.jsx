const ITEMS = ['Free Shipping Over $75', 'Iron-Grade Steel', '30-Day Return', 'Built For Small Spaces'];

export default function MarqueeStrip() {
  const doubled = [...ITEMS, ...ITEMS];
  return (
    <div className="strip" aria-hidden="true">
      <div className="strip-track">
        {doubled.map((item, i) => (
          <span className="strip-item" key={i}>{item}</span>
        ))}
      </div>
    </div>
  );
}
