import Foundation

// Synthetic frozen ATA V1 fixtures. Never downloaded from a backend.
enum ATAFoundationFixtures {
    static let portfolio = #"""
        {
          "revision": 7,
          "snapshot_id": "00000000-0000-4000-8000-000000000104",
          "confirmed_at": "2026-09-25T12:00:03.000000Z",
          "accounts": [
            {
              "id": "00000000-0000-4000-8000-000000000101",
              "name": "Trading",
              "type": "binance",
              "positions": [
                {
                  "symbol": "BTC",
                  "amount": "0.12345678901234567890123456789012345678"
                },
                {
                  "symbol": "ETH",
                  "amount": "3.4503"
                },
                {
                  "symbol": "USDC",
                  "amount": "2000"
                }
              ]
            },
            {
              "id": "00000000-0000-4000-8000-000000000102",
              "name": "External Wallet",
              "type": "external_wallet",
              "positions": [
                {
                  "symbol": "BTC",
                  "amount": "0.2"
                }
              ]
            }
          ],
          "aggregate_positions": [
            {
              "symbol": "BTC",
              "amount": "0.32345678901234567890123456789012345678"
            },
            {
              "symbol": "ETH",
              "amount": "3.4503"
            },
            {
              "symbol": "USDC",
              "amount": "2000"
            }
          ],
          "financial_settings": {
            "monthly_expenses_usd": "250",
            "target_expense_runway_months": "12"
          },
          "core_positions": [
            {
              "symbol": "ETH",
              "hard_floor": "2",
              "preferred_quantity": "2.5",
              "policy_version": 1
            }
          ],
          "limit_orders": [
            {
              "id": "00000000-0000-4000-8000-000000000103",
              "account_id": "00000000-0000-4000-8000-000000000101",
              "asset": "BTC",
              "side": "buy",
              "target_price": "50000",
              "quantity_asset": "0.01",
              "status": "open",
              "created_at": "2026-09-25T12:00:00.000000Z",
              "updated_at": "2026-09-25T12:00:00.000000Z",
              "resolved_at": null
            },
            {
              "id": "00000000-0000-4000-8000-000000000106",
              "account_id": "00000000-0000-4000-8000-000000000101",
              "asset": "ETH",
              "side": "sell",
              "target_price": "3000",
              "quantity_asset": "0.1",
              "status": "filled",
              "created_at": "2026-09-25T12:00:00.000000Z",
              "updated_at": "2026-09-25T12:00:03.000000Z",
              "resolved_at": "2026-09-25T12:00:03.000000Z"
            }
          ]
        }
        """#

    static let detail = #"""
        {
          "run": {
            "run_id": "00000000-0000-4000-8000-000000000105",
            "snapshot_id": "00000000-0000-4000-8000-000000000104",
            "started_at": "2026-09-25T12:00:00.000000Z",
            "status": "completed",
            "completed_at": "2026-09-25T12:00:03.000000Z",
            "market_cutoff": "2026-09-25T12:00:00.000000Z"
          },
          "result": {
            "run_id": "00000000-0000-4000-8000-000000000105",
            "snapshot_id": "00000000-0000-4000-8000-000000000104",
            "generated_at": "2026-09-25T12:00:03.000000Z",
            "market_cutoff": "2026-09-25T12:00:00.000000Z",
            "market": {
              "as_of": "2026-09-25T12:00:00.000000Z",
              "assets": [
                {
                  "symbol": "BTC",
                  "price_usd": "60500",
                  "quoted_at": "2026-09-25T12:00:03.000000Z",
                  "latest_closed_candle_at": "2026-09-25T12:00:00.000000Z",
                  "technical_features": {
                    "change_24h_pct": "-1.5",
                    "change_7d_pct": "2",
                    "rsi_4h": "55",
                    "ema20_4h": "60000",
                    "ema50_4h": "58000",
                    "atr_4h": "1000",
                    "support": "59000",
                    "resistance": "64000"
                  },
                  "completeness": "complete",
                  "latest_closed_price_usd": "60500",
                  "daily_context": {
                    "latest_closed_at": "2026-09-25T00:00:00.000000Z",
                    "closed_price_usd": "60000",
                    "ema20": "58000",
                    "ema50": null,
                    "support": "57000",
                    "resistance": null,
                    "trend": "incomplete"
                  },
                  "closed_1h_candles": [
                    {
                      "closed_at": "2026-09-25T12:00:00.000000Z",
                      "open": "60000",
                      "high": "61000",
                      "low": "59000",
                      "close": "60500"
                    }
                  ]
                }
              ],
              "is_live": true
            },
            "market_regime": "neutral",
            "regime_policy_version": 1,
            "recommendation_policy_version": 1,
            "financial": {
              "total_portfolio_usd": "31920.035735246913580024691358002469135",
              "current_stables_usd": "2000",
              "stable_allocation_percent": "6.265656686813502289436000384889281028",
              "monthly_expenses_usd": "250",
              "target_expense_runway_months": "12",
              "recommended_minimum_stables_usd": "3000",
              "deployable_stables_usd": "0",
              "stable_reserve_deficit_usd": "1000",
              "actual_expense_runway_months": "8",
              "open_buy_commitments_usd": "500",
              "hard_expense_reserve_usd": "3000",
              "market_buffer_usd": "0",
              "potential_trading_liquidity_usd": "0",
              "strategy_dry_powder_usd": "0",
              "recommended_deployment_usd": "0"
            },
            "warnings": [
              "stable_reserve_deficit",
              "future_diagnostic"
            ],
            "recommendations": [
              {
                "recommendation_id": "00000000-0000-4000-8000-000000000108",
                "asset": "BTC",
                "action_type": "keep_limit_order",
                "priority": 1,
                "reason": "Review the recorded order.",
                "existing_order_id": "00000000-0000-4000-8000-000000000103",
                "side": "buy",
                "target_price": "50000",
                "quantity_asset": "0.01",
                "invalidation_condition": "Closed price below support",
                "review_at": "2026-09-25T12:00:00.000000Z",
                "expires_at": null,
                "setup_id": "00000000-0000-4000-8000-000000000107"
              }
            ],
            "reasoning_mode": "AI_ASSISTED",
            "reasoning_model": "synthetic-model",
            "ai_warning": null,
            "configuration": {
              "market_regime_version": 1,
              "stable_reserve_version": 1,
              "whole_plan_version": 3,
              "target_runway_months": "12",
              "market_source": "synthetic",
              "ai_enabled": true,
              "model_name": "synthetic-model",
              "reasoning_effort": "low",
              "ai_context_version": 3,
              "ai_schema_version": 2,
              "ai_prompt_version": 2,
              "ai_failure_category": null,
              "recommendation_parameters": "{\"opaque\":\"preserve exactly\",\"decimal\":\"0.12345678901234567890\"}",
              "active_policy_parameters": "{}",
              "reserve_policy_parameters": null
            },
            "active": {
              "policy_version": 3,
              "setups": [
                {
                  "id": "00000000-0000-4000-8000-000000000107",
                  "asset": "BTC",
                  "direction": "buy",
                  "setup_type": "support_hold",
                  "created_at": "2026-09-25T12:00:00.000000Z",
                  "originating_cutoff": "2026-09-25T12:00:00.000000Z",
                  "status": "confirmed",
                  "limit_price": "60000",
                  "price_source": "support",
                  "invalidation_price": "58000",
                  "invalidation_source": "closed_support",
                  "target_price": "64000",
                  "target_source": "resistance",
                  "risk_reward": "2",
                  "maximum_capital_usd": "200",
                  "score": {
                    "version": 1,
                    "components": [
                      [
                        "trend",
                        20,
                        25
                      ],
                      [
                        "liquidity",
                        15,
                        25
                      ]
                    ]
                  },
                  "related_order_ids": [
                    "00000000-0000-4000-8000-000000000103"
                  ],
                  "levels": [
                    {
                      "price": "60000",
                      "source": "support",
                      "priority": 1
                    }
                  ],
                  "trigger": {
                    "version": 1,
                    "zone_low": "59000",
                    "zone_high": "61000",
                    "atr_at_creation": "1000",
                    "transitions": [
                      {
                        "previous_state": "awaiting_confirmation",
                        "current_state": "confirmed",
                        "transitioned_at": "2026-09-25T12:00:03.000000Z",
                        "market_cutoff": "2026-09-25T12:00:00.000000Z",
                        "timeframe": "1h",
                        "reason": "closed_1h_support_hold_confirmed",
                        "reference_price": "60500"
                      }
                    ],
                    "touched_at": "2026-09-25T12:00:00.000000Z",
                    "highest_observed_price": "61000",
                    "lowest_observed_price": "59000",
                    "trigger_reference_price": "60500",
                    "confirmation_at": "2026-09-25T12:00:03.000000Z",
                    "confirmation_candle": {
                      "closed_at": "2026-09-25T12:00:00.000000Z",
                      "open": "60000",
                      "high": "61000",
                      "low": "59000",
                      "close": "60500"
                    },
                    "expires_at": "2026-09-25T16:00:00.000000Z",
                    "last_processed_1h_candle_at": "2026-09-25T12:00:00.000000Z",
                    "execution_valid": true
                  }
                }
              ],
              "asset_decisions": [
                {
                  "asset": "BTC",
                  "decision": "hold",
                  "quantity": "0.32345678901234567890123456789012345678",
                  "market_value_usd": "19570",
                  "allocation_percent": "60",
                  "core_floor": null,
                  "preferred_core": null,
                  "tradable_quantity": "0.32345678901234567890123456789012345678",
                  "daily_trend": "mixed",
                  "setup_id": "00000000-0000-4000-8000-000000000107"
                }
              ],
              "ranked_setup_ids": [
                "00000000-0000-4000-8000-000000000107"
              ],
              "recommended_deployment_usd": "0",
              "strategy_dry_powder_usd": "0",
              "severity": "update"
            }
          },
          "failure_category": null
        }
        """#

    static let pending = #"""
        {
          "run": {
            "run_id": "00000000-0000-4000-8000-000000000109",
            "snapshot_id": "00000000-0000-4000-8000-000000000104",
            "started_at": "2026-09-25T12:00:00.000000Z",
            "status": "running",
            "completed_at": null,
            "market_cutoff": null
          },
          "result": null,
          "failure_category": null
        }
        """#

    static let list = #"""
        {
          "analyses": [
            {
              "run_id": "00000000-0000-4000-8000-000000000105",
              "snapshot_id": "00000000-0000-4000-8000-000000000104",
              "started_at": "2026-09-25T12:00:00.000000Z",
              "status": "completed",
              "completed_at": "2026-09-25T12:00:03.000000Z",
              "market_cutoff": "2026-09-25T12:00:00.000000Z"
            },
            {
              "run_id": "00000000-0000-4000-8000-000000000109",
              "snapshot_id": "00000000-0000-4000-8000-000000000104",
              "started_at": "2026-09-25T12:00:00.000000Z",
              "status": "running",
              "completed_at": null,
              "market_cutoff": null
            }
          ]
        }
        """#

}
