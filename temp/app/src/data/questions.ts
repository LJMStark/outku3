import type { Question } from '@/types/onboarding';

export const discoveryQuestion: Question = {
  id: 'discovery',
  title: 'How did you discover Inku?',
  type: 'single',
  options: [
    { id: 'chatgpt', label: 'ChatGPT (or other AI)', icon: 'MessageSquare' },
    { id: 'facebook', label: 'Facebook', icon: 'Facebook' },
    { id: 'tiktok', label: 'TikTok', icon: 'Music' },
    { id: 'twitter', label: 'X (Twitter)', icon: 'Twitter' },
    { id: 'instagram', label: 'Instagram', icon: 'Instagram' },
    { id: 'kickstarter', label: 'Kickstarter', icon: 'Rocket' },
    { id: 'appstore', label: 'App Store', icon: 'Smartphone' },
    { id: 'friends', label: 'Friends or Family', icon: 'Users' },
    { id: 'other', label: 'Other', icon: 'Search' },
  ],
};

export const userTypeQuestion: Question = {
  id: 'userType',
  title: 'Which of these sound like you?',
  subtitle: "Pick all that fit — Inku's taking notes!",
  type: 'multiple',
  options: [
    { id: 'multiple-calendars', label: 'I manage multiple calendars', emoji: '📅' },
    { id: 'juggle-work-home', label: 'I juggle work & home', emoji: '🏠' },
    { id: 'brain-cluttered', label: 'My brain feels cluttered', emoji: '🧠' },
    { id: 'fun-planner', label: 'I need a fun/engaging planner', emoji: '🎨' },
  ],
};

export const strugglesQuestion: Question = {
  id: 'struggles',
  title: 'What do you struggle with?',
  subtitle: 'This will help us personalize Inku for you',
  type: 'single',
  options: [
    { id: 'context-switching', label: 'Constant context switching', emoji: '🔄' },
    { id: 'too-many-apps', label: 'Too many apps to keep a track of things', emoji: '📱' },
    { id: 'lose-focus', label: 'I lose focus easily', emoji: '🌫️' },
    { id: 'nothing', label: 'Nothing in particular', emoji: '🙂' },
  ],
};

export const scheduleFullnessQuestion: Question = {
  id: 'scheduleFullness',
  title: 'How full is your plate right now?',
  subtitle: 'Events, tasks, chores, side projects—everything counts',
  type: 'single',
  options: [
    { id: 'multiple-daily', label: 'Multiple things daily', emoji: '📅' },
    { id: 'absolutely-packed', label: 'Absolutely packed', emoji: '🔥' },
    { id: 'few-weekly', label: 'A few things a week', emoji: '📅' },
    { id: 'pretty-light', label: 'Pretty light', emoji: '🌤️' },
  ],
};

export const schedulePredictabilityQuestion: Question = {
  id: 'schedulePredictability',
  title: 'How does your schedule feel predictable or chaotic?',
  subtitle: 'No judgment—we meet you where you are',
  type: 'single',
  options: [
    { id: 'unpredictable', label: 'Totally unpredictable', emoji: '🗓️' },
    { id: 'depends', label: 'Depends on the week', emoji: '🔥' },
    { id: 'predictable', label: 'Mostly predictable', emoji: '📅' },
  ],
};

export const calendarUsageQuestion: Question = {
  id: 'calendarUsage',
  title: 'How do you use your calendar today?',
  subtitle: 'No judgment—we meet you where you are',
  type: 'single',
  options: [
    { id: 'work-only', label: 'Only for work meetings', emoji: '💼' },
    { id: 'dont-use', label: "I don't really use one", emoji: '🤷' },
    { id: 'everything', label: 'Everything goes in my calendar', emoji: '🗂️' },
  ],
};

export const taskTrackingQuestion: Question = {
  id: 'taskTracking',
  title: 'What about tracking tasks and to-dos?',
  subtitle: 'Again, no wrong answer here',
  type: 'single',
  options: [
    { id: 'wing-it', label: 'Nope, I wing it', emoji: '🤷' },
    { id: 'work-only', label: 'Only work stuff', emoji: '💼' },
    { id: 'cant-live', label: "Can't live without my task list", emoji: '✅' },
  ],
};

export const timeControlQuestion: Question = {
  id: 'timeControl',
  title: 'How much control do you feel over your time right now?',
  subtitle: 'Answer honestly, no wrong answers',
  type: 'single',
  options: [
    { id: 'barely', label: 'Barely keeping up', emoji: '😵‍💫' },
    { id: 'overwhelmed', label: 'Completely overwhelmed', emoji: '😫' },
    { id: 'in-control', label: "I'm in control", emoji: '✅' },
    { id: 'some-control', label: 'Some control, some chaos', emoji: '🌤️' },
  ],
};

export const allQuestions = [
  discoveryQuestion,
  userTypeQuestion,
  strugglesQuestion,
  scheduleFullnessQuestion,
  schedulePredictabilityQuestion,
  calendarUsageQuestion,
  taskTrackingQuestion,
  timeControlQuestion,
];
