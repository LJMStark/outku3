import { PromptStudio } from "@/components/PromptStudio";
import promptSpec from "@/lib/prompt-spec.json";

export default function Home() {
  return <PromptStudio spec={promptSpec as unknown as Parameters<typeof PromptStudio>[0]["spec"]} />;
}
