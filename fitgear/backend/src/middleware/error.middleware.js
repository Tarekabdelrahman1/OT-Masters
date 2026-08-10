function notFound(req, res, next) {
  res.status(404).json({ error: `Route ${req.originalUrl} not found.` });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({ error: err.message || 'Something went wrong.' });
}

module.exports = { notFound, errorHandler };
