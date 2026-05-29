package dev.foresterworkload;

import org.forester.phylogeny.Phylogeny;
import org.forester.phylogeny.PhylogenyNode;
import org.forester.util.ForesterUtil;
import org.forester.msa.Msa;
import org.forester.msa.BasicMsa;
import org.forester.sequence.BasicSequence;
import org.forester.sequence.MolecularSequence;

import java.util.ArrayList;
import java.util.List;

public class ForesterWorkload {

    public static void main(String[] args) {
        // Phylogeny types — loaded by biojava-alignment's tree-building path
        Phylogeny phy = new Phylogeny();
        PhylogenyNode root = new PhylogenyNode();
        root.setName("root");
        phy.setRoot(root);
        phy.setRooted(true);

        PhylogenyNode child = new PhylogenyNode();
        child.setName("child");
        root.addAsChild(child);

        // MSA types — loaded by biojava-alignment's pairwise-alignment path
        List<MolecularSequence> seqs = new ArrayList<>();
        seqs.add(BasicSequence.createAaSequence("seq1", "ACDEF"));
        seqs.add(BasicSequence.createAaSequence("seq2", "ACDEF"));
        Msa msa = BasicMsa.createInstance(seqs);
        msa.getNumberOfSequences();

        // ForesterUtil utility path
        ForesterUtil.LINE_SEPARATOR.length();
        ForesterUtil.isEmpty((List<?>) null);
        ForesterUtil.collapseWhiteSpace("a b c");
    }
}
