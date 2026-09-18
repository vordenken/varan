# language: en
Feature: Visible app startup
  As a user
  I want immediate visible feedback during a cold start
  so that a slow local initialization does not look like a crash.

  Scenario: The local database is prepared during a cold start
    Given the app is completely closed
    When I open Varan
    Then a launch background matching the system appearance is displayed
    And a loading view is displayed while the database initializes
    And the profile or stack view is displayed after successful initialization

  Scenario: The local database cannot be opened
    Given the app cannot open its local database
    When initialization fails
    Then a clear error message is displayed
    And I can retry initialization