require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const authRoutes = require('./routes/auth.routes');
const productsRoutes = require('./routes/products.routes');
const ordersRoutes = require('./routes/orders.routes');
const { notFound, errorHandler } = require('./middleware/error.middleware');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.CLIENT_ORIGIN || 'http://localhost:5173' }));
app.use(express.json());
app.use(morgan('dev'));

// Liveness/readiness probe for Kubernetes
app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use('/api/auth', authRoutes);
app.use('/api/products', productsRoutes);
app.use('/api/orders', ordersRoutes);

app.use(notFound);
app.use(errorHandler);

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`FitGear API listening on port ${PORT}`));
