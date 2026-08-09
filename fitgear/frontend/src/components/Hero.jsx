import { Link } from 'react-router-dom';

export default function Hero() {
  return (
    <section className="hero">
      <div>
        <div className="eyebrow">Home &amp; Garage Gym Supply</div>
        <h1 className="hero-title display">
          TRAIN<br />WHERE YOU<br /><span className="outline">LIVE.</span>
        </h1>
        <p className="hero-sub">
          Loaded barbells, resistance bands and cardio gear built for the garage, not the showroom.
          No frills. No subscription. Just weight that stacks up.
        </p>
        <div className="hero-actions">
          <Link to="/shop" className="btn-primary">Shop Equipment</Link>
          <a href="#bundles" className="btn-ghost">See Bundles</a>
        </div>
      </div>

      <div className="bar-rig">
        <svg className="bar-svg" viewBox="0 0 420 200" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Illustration of a loading barbell">
          <rect x="20" y="94" width="380" height="10" rx="5" fill="#3a3b3f" />
          <g className="plate-load p1"><rect x="52" y="55" width="16" height="88" rx="3" fill="#4a4b50" /></g>
          <g className="plate-load p2"><rect x="82" y="40" width="22" height="118" rx="4" fill="#EDE9DF" /></g>
          <g className="plate-load p3"><rect x="118" y="30" width="26" height="138" rx="5" fill="#FF4E1F" /></g>
          <g className="plate-load p4"><rect x="158" y="40" width="22" height="118" rx="4" fill="#EDE9DF" /></g>
          <g className="plate-load p1"><rect x="330" y="55" width="16" height="88" rx="3" fill="#4a4b50" /></g>
          <g className="plate-load p2"><rect x="298" y="40" width="22" height="118" rx="4" fill="#EDE9DF" /></g>
          <g className="plate-load p3"><rect x="256" y="30" width="26" height="138" rx="5" fill="#FF4E1F" /></g>
          <g className="plate-load p4"><rect x="220" y="40" width="22" height="118" rx="4" fill="#EDE9DF" /></g>
        </svg>
        <div className="load-readout">LOADED&nbsp;&nbsp;<b>226</b>&nbsp;LB</div>
      </div>
    </section>
  );
}
