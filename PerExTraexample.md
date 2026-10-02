# PRD — Personal Expense Tracker

## 1. Product Context

### Problem

Users often record expenses inconsistently, making it difficult
to understand where their spending and stay within budget.

### Goal

Help users record, categorize, and review their expenses to
understand spending patterns and monitor
their monthly budget.

### Target Users

- Individuals who want to track personal expenses.
- Users who want to monitor spending against a monthly budget.

### Scope

In Scope:
- Record and categorize expenses
- View and filter expense history
- Set monthly budgets
- View spending summaries

Out of Scope:
- Bank integration
- Automatic transaction import
- Investment management
- Tax calculation

## 2. Use Cases

### UC-01 - Record Expense
User records an expense with:
- Amount
- Category
- Date
- Description

### UC-02 - View Expense History
User views and filter expenses by date or category.

### UC-03 - Set Monthly Budget
User sets a spending limit for a month.

### UC-04 - View Spending Summary
User selects a month to view:
- Total spending
- Spending by category
- Budget, when set
- Remaining budget, when a budget is set

## 3. Product Rules

- Expense amount must be greater than zero.
- Expense category and date are required.
- Each expense belongs to the user who records it.
- A monthly budget applies to one user and one month.
- Setting a budget again for the same month replaces the previous budget.
- Spending is calculated from expenses in the selected month.
- If no budget exists, spending remains viewable.
- Remaining budget = budget - total spending.


## 4. Requirements

### FR-01 - Create Expense
Users can create an expense.
Invalid expenses must be rejected.

### FR-02 - Set Monthly Budget
Users can set or update budget for a selected month.
When a budget already exists for that month,
setting a new budget replaces the previous budget.

### FR-03 - View Spending Summary
users can view spending for a selected month,
including total spending and spending by category.

## 5. Acceptance Criteria

- Valid expenses are recorded and appears in the user's expense history.
- Invalid expense cannot be recorded.
- Users can set or update monthly budget.
- The selected month's spending is shown by category and total.
- Budget information is shown when a budget exists.
- Spending remains viewable when no budget exists.
