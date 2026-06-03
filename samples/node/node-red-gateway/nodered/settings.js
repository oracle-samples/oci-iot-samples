module.exports = {
  uiPort: process.env.PORT || 1880,
  flowFile: "flows.json",
  flowFilePretty: true,
  logging: {
    console: {
      level: "info",
      metrics: false,
      audit: false,
    },
  },
  exportGlobalContextKeys: false,
  functionGlobalContext: {},
};
