module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    // Matches the Node 24 runtime the functions deploy to.
    "ecmaVersion": 2022,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    // Keep the 80-col rule for code, but exempt long HTML/email strings,
    // template literals, and URLs where wrapping would hurt readability.
    "max-len": ["error", {
      "code": 80,
      "ignoreStrings": true,
      "ignoreTemplateLiterals": true,
      "ignoreUrls": true,
    }],
  },
  overrides: [
    {
      files: ["**/*.spec.*", "**/*.test.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
