import { createContext, useContext, useEffect, useState } from 'react';

const CartContext = createContext(null);

export function CartProvider({ children }) {
  const [items, setItems] = useState(() => {
    try {
      const stored = localStorage.getItem('fitgear_cart');
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  });

  useEffect(() => {
    localStorage.setItem('fitgear_cart', JSON.stringify(items));
  }, [items]);

  function addItem(product, quantity = 1) {
    setItems((prev) => {
      const existing = prev.find((i) => i.product.id === product.id);
      if (existing) {
        return prev.map((i) =>
          i.product.id === product.id ? { ...i, quantity: i.quantity + quantity } : i
        );
      }
      return [...prev, { product, quantity }];
    });
  }

  function updateQuantity(productId, quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    setItems((prev) => prev.map((i) => (i.product.id === productId ? { ...i, quantity } : i)));
  }

  function removeItem(productId) {
    setItems((prev) => prev.filter((i) => i.product.id !== productId));
  }

  function clearCart() {
    setItems([]);
  }

  const count = items.reduce((sum, i) => sum + i.quantity, 0);
  const totalCents = items.reduce((sum, i) => sum + i.quantity * i.product.price_cents, 0);

  return (
    <CartContext.Provider value={{ items, addItem, updateQuantity, removeItem, clearCart, count, totalCents }}>
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error('useCart must be used within a CartProvider');
  return ctx;
}
