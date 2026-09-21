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
    And onboarding or the saved profile view is displayed after successful initialization

  Scenario: Set up the first Komodo instance
    Given no Komodo instance is saved
    When I open Varan
    Then onboarding explains resource monitoring, operational insights, and multiple instances
    And I can validate and save my first Komodo connection
    And I can open Varan after the connection succeeds

  Scenario: Add another instance during onboarding
    Given I successfully added my first Komodo instance during onboarding
    When I choose to add another instance
    Then the shared connection form is displayed again
    And every successfully validated instance is saved separately

  Scenario: Return to onboarding after removing every instance
    Given I remove the final saved Komodo instance
    Then onboarding is displayed again

  Scenario: The local database cannot be opened
    Given the app cannot open its local database
    When initialization fails
    Then a clear error message is displayed
    And I can retry initialization
