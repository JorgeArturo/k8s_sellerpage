import { useEffect, useState } from 'react'
import { api } from '../api'

export default function Home() {
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    api
      .getProducts()
      .then(setProducts)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <div className="page container">
        <p className="empty-state">Loading products...</p>
      </div>
    )
  }

  if (error) {
    return (
      <div className="page container">
        <div className="alert alert-error">{error}</div>
      </div>
    )
  }

  return (
    <div className="page container">
      <h1 className="page-title">Marketplace</h1>
      <p className="page-subtitle">Browse our catalog of products</p>

      {products.length === 0 ? (
        <div className="empty-state card">
          <p>No products available yet.</p>
          <p style={{ marginTop: '0.5rem', fontSize: '0.9rem' }}>
            An administrator can add products from the admin panel.
          </p>
        </div>
      ) : (
        <div className="product-grid">
          {products.map((product) => (
            <article key={product.id} className="product-card">
              {product.image_url ? (
                <img
                  src={product.image_url}
                  alt={product.name}
                  className="product-image"
                />
              ) : (
                <div className="product-image-placeholder">📦</div>
              )}
              <div className="product-body">
                <h2 className="product-name">{product.name}</h2>
                <p className="product-desc">{product.description}</p>
                <div className="product-footer">
                  <span className="price">${product.price.toFixed(2)}</span>
                  <span className="stock">{product.stock} in stock</span>
                </div>
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  )
}
