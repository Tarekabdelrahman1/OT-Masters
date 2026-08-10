const fs = require('fs');
const path = require('path');
const db = require('../db');

const categories = [
  { slug: 'free-weights', name: 'Free Weights', plate_label: '45LB', description: 'Dumbbells, kettlebells, plates and bars for raw strength work.' },
  { slug: 'resistance', name: 'Resistance', plate_label: '20LB', description: 'Bands, cables and tubes for mobility and accessory lifts.' },
  { slug: 'cardio', name: 'Cardio', plate_label: '10LB', description: "Jump ropes, sliders and conditioning tools that don't take up a room." },
  { slug: 'recovery', name: 'Recovery', plate_label: '5LB', description: 'Foam rollers, mats and mobility gear for the day after leg day.' },
];

const products = [
  { name: 'Adjustable Barbell Set — 110lb', slug: 'adjustable-barbell-set-110lb', category: 'free-weights', price_cents: 24900, spec_tags: ['STEEL CORE', 'KNURLED'], badge: 'Best Seller', stock: 40, description: 'A full adjustable barbell and plate set for progressive overload at home.' },
  { name: 'Cast-Iron Kettlebell — 35lb', slug: 'cast-iron-kettlebell-35lb', category: 'free-weights', price_cents: 7900, spec_tags: ['POWDER COAT', 'WIDE GRIP'], badge: 'New', stock: 60, description: 'Single-piece cast iron kettlebell with a wide, chalk-friendly handle.' },
  { name: 'Heavy-Duty Resistance Bands (5pk)', slug: 'heavy-duty-resistance-bands-5pk', category: 'resistance', price_cents: 3400, spec_tags: ['10–150 LB', 'LATEX-FREE'], badge: null, stock: 120, description: 'Five resistance levels covering warm-ups through max-effort accessory work.' },
  { name: 'Olympic Weight Plate Pair — 45lb', slug: 'olympic-weight-plate-pair-45lb', category: 'free-weights', price_cents: 18900, spec_tags: ['2" BORE', 'RUBBER COAT'], badge: 'Best Seller', stock: 35, description: 'Rubber-coated Olympic plates sized for a standard 2-inch barbell sleeve.' },
  { name: 'Foldable Slam Ball — 20lb', slug: 'foldable-slam-ball-20lb', category: 'cardio', price_cents: 5900, spec_tags: ['NO-BOUNCE', 'TEXTURED'], badge: null, stock: 50, description: 'No-bounce slam ball built for conditioning circuits and finishers.' },
  { name: 'Speed Jump Rope — Ball Bearing', slug: 'speed-jump-rope-ball-bearing', category: 'cardio', price_cents: 2200, spec_tags: ['ADJUSTABLE', 'ALUMINUM'], badge: 'New', stock: 90, description: 'Ball-bearing swivel rope for double-unders and fast conditioning work.' },
  { name: 'High-Density Foam Roller', slug: 'high-density-foam-roller', category: 'recovery', price_cents: 2900, spec_tags: ['26"', 'FIRM'], badge: null, stock: 70, description: 'Firm-density roller for myofascial release after heavy training days.' },
  { name: 'Fabric Resistance Loop Set (3pk)', slug: 'fabric-resistance-loop-set-3pk', category: 'resistance', price_cents: 1900, spec_tags: ['NON-SLIP', 'LIGHT–HEAVY'], badge: null, stock: 100, description: 'Non-slip fabric loops for glute activation and warm-up sequences.' },
];

async function seed() {
  console.log('Seeding categories...');
  const categoryIds = {};
  for (const c of categories) {
    const res = await db.query(
      `INSERT INTO categories (slug, name, plate_label, description)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name
       RETURNING id, slug`,
      [c.slug, c.name, c.plate_label, c.description]
    );
    categoryIds[c.slug] = res.rows[0].id;
  }

  console.log('Seeding products...');
  for (const p of products) {
    await db.query(
      `INSERT INTO products (name, slug, category_id, price_cents, spec_tags, badge, description, stock)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (slug) DO UPDATE SET price_cents = EXCLUDED.price_cents, stock = EXCLUDED.stock`,
      [p.name, p.slug, categoryIds[p.category], p.price_cents, p.spec_tags, p.badge, p.description, p.stock]
    );
  }

  console.log('Seed complete.');
  process.exit(0);
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
