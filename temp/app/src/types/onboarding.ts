export interface OnboardingState {
  currentPage: number;
  answers: {
    discoverySource?: string;
    userTypes?: string[];
    struggles?: string;
    scheduleFullness?: string;
    schedulePredictability?: string;
    calendarUsage?: string;
    taskTracking?: string;
    timeControl?: string;
  };
  selectedTheme?: string;
  selectedAvatar?: string;
}

export interface Question {
  id: string;
  title: string;
  subtitle?: string;
  type: 'single' | 'multiple';
  options: {
    id: string;
    label: string;
    icon?: string;
    emoji?: string;
  }[];
}

export interface PageProps {
  onNext: () => void;
  onBack?: () => void;
  state: OnboardingState;
  setState: React.Dispatch<React.SetStateAction<OnboardingState>>;
}

export type PageComponent = React.FC<PageProps>;
