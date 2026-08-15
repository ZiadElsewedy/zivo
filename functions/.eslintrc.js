module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2018,
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
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
