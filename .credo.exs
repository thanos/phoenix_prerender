%{
  configs: [
    %{
      name: "default",
      checks: [
        # Or configure it with parameters
        {Credo.Check.Design.AliasUsage, false}
        # ... other checks
      ]
      # ... other config
    }
  ]
}
